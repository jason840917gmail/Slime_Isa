import Phaser from 'phaser';

import type { SupplementalWeaponHitboxPort } from '../../combat/Weapon';
import type { MapBossCamp, MapEnemySafeZone, MapFile } from '../../content/maps/mapFormat';
import { sceneId } from '../../content/scenes/identifiers';
import { getBossDefinition } from '../../content/bosses/BossCatalog';
import { ASSET_MANIFEST, type AssetId } from '../../infrastructure/assets/manifest';
import { PhysicsBody2DNode } from '../../infrastructure/phaser-nodes/PhysicsBody2DNode';
import { Sprite2DNode } from '../../infrastructure/phaser-nodes/Sprite2DNode';
import { PhaserUniversalSceneRuntime, type MountedScene } from '../../infrastructure/scenes/PhaserUniversalSceneRuntime';
import type { PreparedSceneContent } from '../../infrastructure/scenes/PreparedSceneContent';
import { LegacyBossUiBridge, type LegacyBossBarHandle } from '../../infrastructure/scenes/compatibility/LegacyBossUiBridge';
import { LegacyChestUiBridge } from '../../infrastructure/scenes/compatibility/LegacyChestUiBridge';
import { LegacyCombatBridge } from '../../infrastructure/scenes/compatibility/LegacyCombatBridge';
import { LegacyMapPlacementBridge } from '../../infrastructure/scenes/compatibility/LegacyMapPlacementBridge';
import { LegacyPlayerBridge } from '../../infrastructure/scenes/compatibility/LegacyPlayerBridge';
import { LegacyWeaponTargetBridge, type LegacyWeaponManagedTarget } from '../../infrastructure/scenes/compatibility/LegacyWeaponTargetBridge';
import { LegacyWorldAdapter } from '../../infrastructure/scenes/compatibility/LegacyWorldAdapter';
import type { Node } from '../../runtime/scene/Node';
import type { Node2D } from '../../runtime/scene/Node2D';
import { AttackActivation } from '../combat/AttackActivation';
import type { RoutedDamageOutcome } from '../combat/DamageRouter';
import { DamageRouter } from '../combat/DamageRouter';
import type { InteractionProvider, InteractionRouter } from '../interaction/InteractionRouter';
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
  readonly player: Phaser.Physics.Arcade.Sprite;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly health: HealthSystem;
  readonly progress: WorldProgress;
  readonly transaction: InventoryWorldTransaction;
  readonly interactions: InteractionRouter;
  readonly modalStack: ModalStack;
  readonly isPlayerDodging: () => boolean;
  readonly applyPlayerKnockback: (direction: Readonly<{ x: number; y: number }>, strength: number, durationMs: number) => void;
  readonly setChestPaused: (paused: boolean) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'cyan' | 'orange' | 'red', important?: boolean) => void;
  readonly updateLegacyFixed: (deltaMs: number) => void;
  readonly updateLegacyRender: (deltaMs: number) => void;
  readonly transformManagedWeaponDamage: (damage: number, target: LegacyWeaponManagedTarget) => number;
  readonly onManagedWeaponOutcome: (outcome: RoutedDamageOutcome, target: LegacyWeaponManagedTarget | undefined) => void;
  readonly onManagedEnemyDefeated: (enemy: ManagedEnemyDefeat) => void;
  readonly getEnemySafeZones: () => readonly MapEnemySafeZone[];
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
  private readonly playerBridge: LegacyPlayerBridge;
  private readonly combatBridge: LegacyCombatBridge;
  private readonly weaponBridge: LegacyWeaponTargetBridge;
  private readonly chestUi?: LegacyChestUiBridge;
  private readonly bossUi: LegacyBossUiBridge;
  private readonly camps = new Map<string, ManagedCamp>();
  private readonly bosses = new Map<string, ManagedBoss>();
  private readonly ordinaryEnemies = new Map<number, ManagedOrdinaryEnemy>();
  private readonly chests = new Map<string, ChestScript>();
  private readonly bossBars = new Set<ManagedBossBar>();
  private readonly unregisterInteraction: () => void;
  private nextBossSequence = 1;
  private nextEnemySequence = 1;
  private simulationTimeMs = 0;
  private disposed = false;

  constructor(private readonly options: UniversalSceneWorldControllerOptions) {
    this.combatBridge = new LegacyCombatBridge(this.activations, this.damageRouter);
    this.playerBridge = new LegacyPlayerBridge(
      this.damageRouter,
      options.health.managedReceiver,
      {
        getPosition: () => ({ x: options.player.x, y: options.player.y }),
        getBodyBounds: () => {
          const body = options.player.body as Phaser.Physics.Arcade.Body;
          return { x: body.x, y: body.y, width: body.width, height: body.height };
        },
        isDodging: options.isPlayerDodging,
        applyKnockback: options.applyPlayerKnockback,
      },
    );
    this.playerBridge.enter();

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
      [ENEMY_TARGET_SERVICE]: {
        getPrimaryTarget: (sourceNodeId: string) => this.playerBridge.getPrimaryTarget(sourceNodeId),
        getNavigation: (sourceNodeId: string) => this.enemyNavigation(sourceNodeId),
        fireProjectile: (request: EnemyProjectileRequest) => this.fireEnemyProjectile(request),
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
    this.mountAuthoredPlacements();
    this.unregisterInteraction = options.interactions.register('managed-chests', this);
  }

  advanceFrame(deltaSeconds: number): number { return this.runtime.advanceFrame(deltaSeconds); }
  setPaused(paused: boolean): void { this.runtime.setPaused(paused); }
  get managedOrdinaryEnemyCount(): number { return this.ordinaryEnemies.size; }
  get managedBossCount(): number { return this.bosses.size; }
  get managedCampCount(): number { return this.camps.size; }
  get managedChestCount(): number { return this.chests.size; }
  get managedLiveCampCount(): number { return [...this.camps.values()].filter((camp) => camp.script.hasLiveBoss).length; }

  getCandidate() {
    let nearest: { readonly script: ChestScript; readonly position: Readonly<{ x: number; y: number }> } | undefined;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (const script of this.chests.values()) {
      this.syncChestFrame(script);
      const parent = script.get_parent() as Node2D | undefined;
      if (!parent) continue;
      const position = parent.get_global_transform().position;
      const distance = Phaser.Math.Distance.Between(this.options.player.x, this.options.player.y, position.x, position.y);
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
    this.weaponBridge.dispose();
    this.combatBridge.dispose();
    this.runtime.shutdown();
    this.playerBridge.dispose();
    this.chestUi?.dispose();
    this.bossUi.dispose();
    this.camps.clear();
    this.bosses.clear();
    this.ordinaryEnemies.clear();
    this.chests.clear();
    this.bossBars.clear();
  }

  private mountAuthoredPlacements(): void {
    for (const placement of this.options.placementBridge.scenePlacements()) {
      const mount = this.runtime.mountScene(sceneId(placement.sceneId), {
        runtimeNamespace: `managed-${placement.placementId}`,
        persistenceKey: placement.persistenceKey,
        position: { x: placement.x, y: placement.y },
      });
      this.registerLegacyColliders(mount);
      for (const script of descendants(mount.root, ChestScript)) this.chests.set(script.instanceId, script);
      const campScript = descendants(mount.root, BossCampScript)[0];
      const definition = this.options.map.bossCamps?.find((camp) => camp.id === campScript?.campId);
      if (campScript && definition) this.camps.set(campScript.campId, { definition, script: campScript, mount });
    }
  }

  private evaluateCamps(): void {
    const epochNow = Date.now();
    for (const camp of this.camps.values()) {
      const inside = bossPerimeterContains(camp.definition.activationPerimeter, this.options.player.x, this.options.player.y);
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

  private registerLegacyColliders(mount: MountedScene): void {
    const colliders: Phaser.Physics.Arcade.Collider[] = [];
    for (const body of descendants(mount.root, PhysicsBody2DNode)) {
      if (body.isStaticBody) colliders.push(this.options.scene.physics.add.collider(this.options.player, body.physicsObject));
      else {
        colliders.push(this.options.scene.physics.add.collider(body.physicsObject, this.options.collisionTiles));
        colliders.push(this.options.scene.physics.add.collider(this.options.player, body.physicsObject));
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

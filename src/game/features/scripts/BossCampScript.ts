import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { sensorShapeContainsPoint, type SensorShape } from '../../runtime/scene/physics/SensorGeometry';
import { bossCampSpawnEligible, resolveBossCampSpawnSuppression } from '../bosses/BossCampBehavior';

export const BOSS_CAMP_PROGRESS_SERVICE = 'world.boss-camp-progress';
export const BOSS_SCENE_SPAWNER_SERVICE = 'world.scene-spawner';
export const BOSS_UI_SERVICE = 'ui.boss-status';

export interface BossCampProgressPort {
  getRespawnReadyAt(mapId: string, campId: string): number | undefined;
  setRespawnReadyAt(mapId: string, campId: string, epochMs: number | undefined): void;
  markBossDefeated(bossId: string): void;
}

export interface BossSceneSpawnRequest {
  readonly sceneId: string;
  readonly campId: string;
  readonly bossId: string;
  readonly parentRuntimeId: string;
  readonly spawn: Readonly<{ x: number; y: number }>;
}

export interface BossSceneSpawnerPort {
  spawnBoss(request: BossSceneSpawnRequest): void;
  removeBoss(campId: string): void;
}

export interface BossStatusViewPort {
  showBoss(campId: string, bossId: string): void;
  hideBoss(campId: string, defeated: boolean): void;
}

function isJsonObject(value: unknown): value is Readonly<Record<string, unknown>> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export class BossCampScript extends ScriptNode {
  readonly mapId: string;
  readonly campId: string;
  readonly bossId: string;
  readonly bossSceneId: string;
  readonly respawnMs: number;
  private liveBoss = false;
  private observedOutsideAfterDefeat = true;
  private suppressSpawnUntilOutside = false;
  private progress?: BossCampProgressPort;
  private spawner?: BossSceneSpawnerPort;
  private statusView?: BossStatusViewPort;

  constructor(context: NodeConstructionContext) {
    if (!context.scriptId) throw new Error('BossCampScript requires a registered script identity.');
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId, exportedProperties: context.properties });
    this.mapId = typeof context.properties.mapId === 'string' ? context.properties.mapId : '';
    this.campId = typeof context.properties.campId === 'string' ? context.properties.campId : '';
    this.bossId = typeof context.properties.bossId === 'string' ? context.properties.bossId : '';
    const bossScene = context.properties.bossScene;
    this.bossSceneId = isJsonObject(bossScene)
      && typeof bossScene.sceneId === 'string' ? bossScene.sceneId : '';
    this.respawnMs = typeof context.properties.respawnMs === 'number' ? context.properties.respawnMs : 0;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.progress = this.service<BossCampProgressPort>(BOSS_CAMP_PROGRESS_SERVICE);
    this.spawner = this.service<BossSceneSpawnerPort>(BOSS_SCENE_SPAWNER_SERVICE);
    this.statusView = this.service<BossStatusViewPort>(BOSS_UI_SERVICE);
    this.observedOutsideAfterDefeat = this.progress.getRespawnReadyAt(this.mapId, this.campId) === undefined;
    this.entryDisposables.add(() => {
      this.spawner?.removeBoss(this.campId);
      this.statusView?.hideBoss(this.campId, false);
      this.liveBoss = false;
    });
  }

  get hasLiveBoss(): boolean { return this.liveBoss; }

  containsActivationPoint(x: number, y: number): boolean {
    const area = this.getReference('activationArea')?.configuredTarget as { contactShapes?: () => readonly SensorShape[] } | undefined;
    return area?.contactShapes?.().some((shape) => sensorShapeContainsPoint(shape, x, y)) ?? false;
  }

  evaluateActivation(insideActivation: boolean, epochNow: number): boolean {
    const suppression = resolveBossCampSpawnSuppression(this.suppressSpawnUntilOutside, insideActivation);
    this.suppressSpawnUntilOutside = suppression.suppressSpawnUntilOutside;
    if (suppression.blocksSpawnThisUpdate) return false;
    const respawnReadyAt = this.progress?.getRespawnReadyAt(this.mapId, this.campId);
    if (respawnReadyAt !== undefined && !insideActivation) this.observedOutsideAfterDefeat = true;
    if (!bossCampSpawnEligible({
      hasLiveBoss: this.liveBoss,
      insideActivation,
      respawnReadyAtEpochMs: respawnReadyAt,
      observedOutsideAfterDefeat: this.observedOutsideAfterDefeat,
      epochNow,
    })) return false;
    this.spawn();
    return true;
  }

  onBossDefeated(epochNow: number): void {
    if (!this.liveBoss) return;
    this.liveBoss = false;
    this.observedOutsideAfterDefeat = false;
    this.progress?.markBossDefeated(this.bossId);
    this.progress?.setRespawnReadyAt(this.mapId, this.campId, epochNow + this.respawnMs);
    this.statusView?.hideBoss(this.campId, true);
    this.getSignal<{ campId: string; bossId: string }>('boss_defeated')?.emit({ campId: this.campId, bossId: this.bossId });
    this.emitGuardChanged(false);
  }

  resetActiveFight(): void {
    if (!this.liveBoss) return;
    this.spawner?.removeBoss(this.campId);
    this.statusView?.hideBoss(this.campId, false);
    this.liveBoss = false;
    this.suppressSpawnUntilOutside = true;
    this.emitGuardChanged(false);
  }

  isChestGuarded(instanceId: string): boolean {
    const guarded = this.exportedProperties.guardedChestInstanceId;
    return this.liveBoss && typeof guarded === 'string' && guarded === instanceId;
  }

  private spawn(): void {
    const parent = this.getReference('activeBosses')?.configuredTarget;
    if (!parent) throw new Error(`Boss camp '${this.campId}' has no active-boss container.`);
    const spawnValue = this.exportedProperties.spawn;
    const spawn = Array.isArray(spawnValue) && spawnValue.length === 2
      ? { x: Number(spawnValue[0]), y: Number(spawnValue[1]) }
      : { x: 0, y: 0 };
    this.liveBoss = true;
    this.observedOutsideAfterDefeat = false;
    this.progress?.setRespawnReadyAt(this.mapId, this.campId, undefined);
    const request = { sceneId: this.bossSceneId, campId: this.campId, bossId: this.bossId, parentRuntimeId: parent.runtimeId, spawn };
    this.spawner?.spawnBoss(request);
    this.statusView?.showBoss(this.campId, this.bossId);
    this.getSignal<BossSceneSpawnRequest>('boss_spawn_requested')?.emit(request);
    this.emitGuardChanged(true);
  }

  private emitGuardChanged(guarded: boolean): void {
    this.getSignal<{ instanceId: string; guarded: boolean }>('guard_changed')?.emit({
      instanceId: String(this.exportedProperties.guardedChestInstanceId ?? ''),
      guarded,
    });
  }
}

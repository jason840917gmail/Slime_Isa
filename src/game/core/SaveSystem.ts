import { initialLocation, createInitialRunState } from '../content/initial-state/InitialRun';
import { mapRepository } from '../infrastructure/maps/MapRepository';
import {
  SaveRepositoryError,
  saveRepository,
} from '../infrastructure/persistence/SaveRepository';
import {
  SAVE_SCHEMA_VERSION,
  type GameLocationData,
  type GameSaveData,
  type NamedSaveMetadata,
  type NamedSaveSnapshot,
  type SaveValidationIssue,
} from '../infrastructure/persistence/SaveSchema';
import { playerInventory } from '../systems/Inventory';
import { questTracker } from '../quests/QuestTracker';
import { worldProgress } from '../features/progression/WorldProgress';
import { gameEvents } from './EventBus';
import { gameState } from './GameState';
import { queueRunNavigation, type RunNavigationKind } from '../features/world-navigation/AreaNavigation';

export type SaveResult =
  | { readonly ok: true; readonly metadata: NamedSaveMetadata }
  | { readonly ok: false; readonly message: string; readonly saveId?: string };

export type LoadResult =
  | { readonly ok: true; readonly snapshot: NamedSaveSnapshot }
  | { readonly ok: false; readonly message: string; readonly saveId?: string };

export type ResetResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly message: string };

type LocationProvider = () => GameLocationData;

class SaveSystem {
  private autoSaveStarted = false;
  private autoSaveTimer: number | undefined;
  private locationProvider?: LocationProvider;
  private activeLocation: GameLocationData = initialLocation();
  private playTimeStartedAt = Date.now();
  private playTimeBaseMs = 0;
  private runInstalled = false;

  startAutoSave(): void {
    if (this.autoSaveStarted) return;
    this.autoSaveStarted = true;
    gameEvents.on('coins.changed', this.scheduleRecovery, this);
    gameEvents.on('boost.changed', this.scheduleRecovery, this);
    gameEvents.on('hp.changed', this.scheduleRecovery, this);
    gameEvents.on('xp.changed', this.scheduleRecovery, this);
    gameEvents.on('energy.changed', this.scheduleRecovery, this);
    gameEvents.on('perk.taken', this.scheduleRecovery, this);
    gameEvents.on('inventory.changed', this.scheduleRecovery, this);
    gameEvents.on('weapon.loadout.changed', this.scheduleRecovery, this);
    gameEvents.on('weapon.equipped', this.scheduleRecovery, this);
    gameEvents.on('quest.changed', this.scheduleRecovery, this);
    gameEvents.on('world.progress.changed', this.scheduleRecovery, this);
    window.addEventListener('pagehide', this.saveOnPageHide);
  }

  setLocationProvider(provider: LocationProvider): () => void {
    this.locationProvider = provider;
    return () => {
      if (this.locationProvider === provider) this.locationProvider = undefined;
    };
  }

  currentLocation(): GameLocationData {
    const provided = this.locationProvider?.();
    if (provided && this.isLocation(provided)) {
      this.activeLocation = { ...provided };
    }
    return { ...this.activeLocation };
  }

  captureCurrentState(location = this.currentLocation()): GameSaveData {
    return {
      player: gameState.serialize(),
      inventory: playerInventory.serialize(),
      quests: questTracker.serialize(),
      location: { ...location },
      world: worldProgress.serialize(),
      playTimeMs: this.playTimeBaseMs + Math.max(0, Date.now() - this.playTimeStartedAt),
    };
  }

  install(data: GameSaveData): void {
    gameState.load(data.player);
    playerInventory.load(data.inventory);
    questTracker.load([...data.quests]);
    worldProgress.load(data.world);
    this.activeLocation = { ...data.location };
    this.playTimeBaseMs = data.playTimeMs;
    this.playTimeStartedAt = Date.now();
    this.runInstalled = true;
  }

  hasInstalledRun(): boolean {
    return this.runInstalled;
  }

  loadRecovery(): GameSaveData | null {
    const data = saveRepository.readRecovery();
    if (!data) return null;
    this.install(data);
    saveRepository.markLegacyMigrationComplete();
    gameEvents.emit('save.loaded', { slot: 'recovery' });
    return data;
  }

  startNewRun(): GameSaveData {
    const initial = createInitialRunState();
    this.install(initial);
    return initial;
  }

  createNamedSave(name: string, location = this.currentLocation()): SaveResult {
    return this.repositoryResult(() => saveRepository.create(name, this.captureCurrentState(location)));
  }

  overwriteNamedSave(saveId: string, location = this.currentLocation()): SaveResult {
    return this.repositoryResult(() => saveRepository.overwrite(saveId, this.captureCurrentState(location)));
  }

  listNamedSaves(): readonly NamedSaveMetadata[] {
    return saveRepository.list();
  }

  namedSaveValidationIssues(): readonly SaveValidationIssue[] {
    return saveRepository.validationIssues();
  }

  recoveryValidationIssue(): SaveValidationIssue | undefined {
    return saveRepository.validationIssues().find((entry) => entry.saveId === undefined);
  }

  namedSave(saveId: string): NamedSaveSnapshot | null {
    return saveRepository.read(saveId);
  }

  deleteNamedSave(saveId: string): boolean {
    return saveRepository.delete(saveId);
  }

  async loadNamedSave(saveId: string): Promise<LoadResult> {
    const snapshot = saveRepository.read(saveId);
    if (!snapshot) {
      const issue = saveRepository.validationIssues().find((entry) => entry.saveId === saveId);
      return { ok: false, saveId, message: issue?.reason ?? 'That save could not be found.' };
    }
    const loadedMap = await mapRepository.load(snapshot.data.location.mapId);
    if (!loadedMap) {
      return { ok: false, saveId, message: `The authored map '${snapshot.data.location.mapId}' is unavailable.` };
    }
    if (!this.isLocationInsideMap(snapshot.data.location, loadedMap.dimensions.width, loadedMap.dimensions.height)) {
      return { ok: false, saveId, message: 'The saved player location is invalid.' };
    }
    return this.queueNavigation(snapshot.data, 'load', loadedMap.map.mapId)
      ? { ok: true, snapshot }
      : { ok: false, saveId, message: 'The load request could not be started.' };
  }

  resetRun(): ResetResult {
    const initial = createInitialRunState();
    return this.queueNavigation(initial, 'reset', initial.location.mapId)
      ? { ok: true }
      : { ok: false, message: 'The reset request could not be started.' };
  }

  completeResetHandoff(): void {
    saveRepository.clearRecovery();
  }

  discardRecoveryAndStartNewRun(): GameSaveData {
    saveRepository.clearRecovery();
    return this.startNewRun();
  }

  writeRecovery(location = this.currentLocation()): boolean {
    if (this.autoSaveTimer !== undefined) {
      window.clearTimeout(this.autoSaveTimer);
      this.autoSaveTimer = undefined;
    }
    const saved = saveRepository.writeRecovery(this.captureCurrentState(location));
    if (saved) gameEvents.emit('save.done', { slot: 'recovery' });
    return saved;
  }

  /** Compatibility alias for older callers; this never touches named saves. */
  save(): boolean {
    return this.writeRecovery();
  }

  /** Compatibility recovery loader. */
  load(): boolean {
    return this.loadRecovery() !== null;
  }

  hasSave(): boolean {
    return saveRepository.hasRecovery();
  }

  deleteSave(saveId: string): void {
    saveRepository.delete(saveId);
  }

  savedAt(): number | null {
    return this.hasSave() ? Date.now() : null;
  }

  private queueNavigation(data: GameSaveData, kind: RunNavigationKind, mapId: string): boolean {
    try {
      queueRunNavigation(kind, data, mapId);
      return true;
    } catch {
      return false;
    }
  }

  private repositoryResult(action: () => NamedSaveMetadata): SaveResult {
    try {
      const metadata = action();
      gameEvents.emit('save.done', { slot: metadata.saveId });
      return { ok: true, metadata };
    } catch (error) {
      if (error instanceof SaveRepositoryError) return { ok: false, message: error.message, saveId: error.saveId };
      return { ok: false, message: 'The save could not be completed.' };
    }
  }

  private scheduleRecovery = (): void => {
    if (this.autoSaveTimer !== undefined) window.clearTimeout(this.autoSaveTimer);
    this.autoSaveTimer = window.setTimeout(() => {
      this.autoSaveTimer = undefined;
      this.writeRecovery();
    }, 250);
  };

  private saveOnPageHide = (): void => {
    this.writeRecovery();
  };

  private isLocation(value: GameLocationData): boolean {
    return typeof value.areaId === 'string'
      && typeof value.mapId === 'string'
      && this.isFiniteLocation(value)
      && ['up', 'down', 'left', 'right'].includes(value.facing);
  }

  private isFiniteLocation(value: GameLocationData): boolean {
    return Number.isFinite(value.x) && Number.isFinite(value.y);
  }

  private isLocationInsideMap(value: GameLocationData, width: number, height: number): boolean {
    return this.isFiniteLocation(value)
      && value.x >= 0
      && value.y >= 0
      && value.x < width
      && value.y < height;
  }
}

export const saveSystem = new SaveSystem();
export { SAVE_SCHEMA_VERSION };

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
import { repairQuestStates } from '../infrastructure/persistence/quests/QuestStateRepair';
import { worldProgress } from '../features/progression/WorldProgress';
import { storyProgress } from '../features/progression/StoryProgress';
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
    gameEvents.on('energy.changed', this.scheduleRecovery, this);
    gameEvents.on('inventory.changed', this.scheduleRecovery, this);
    gameEvents.on('weapon.loadout.changed', this.scheduleRecovery, this);
    gameEvents.on('weapon.equipped', this.scheduleRecovery, this);
    gameEvents.on('quest.changed', this.scheduleRecovery, this);
    gameEvents.on('world.progress.changed', this.scheduleRecovery, this);
    gameEvents.on('story.changed', this.scheduleRecovery, this);
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
      story: storyProgress.serialize(),
      playTimeMs: this.playTimeBaseMs + Math.max(0, Date.now() - this.playTimeStartedAt),
    };
  }

  install(data: GameSaveData): void {
    // Validate and install the quest snapshot before mutating the other run
    // stores. QuestService.load is atomic, so malformed quest data is rejected
    // before player, inventory, or world state is touched. Quest states from an
    // older build are first fitted to the current catalog, so they load.
    const { states, repairs } = repairQuestStates(data.quests);
    if (repairs.length > 0) console.warn(`Saved quest progress was adjusted to this version:\n  ${repairs.join('\n  ')}`);
    questTracker.load([...states]);
    gameState.load(data.player);
    // A run saved at the moment of defeat wakes with full health rather than dead.
    if (gameState.hp <= 0) gameState.revive();
    playerInventory.load(data.inventory);
    worldProgress.load(data.world);
    storyProgress.load(data.story);
    questTracker.restoreKnownFacts({
      discoveredAreas: data.world.discoveredAreas,
      defeatedBossIds: data.world.defeatedBossIds,
      talkedNpcIds: data.story?.talkedNpcIds,
      worldFlags: data.story?.worldFlags,
    });
    // WorldScene calls questTracker.start() after quest notification listeners
    // exist. That boundary evaluates prerequisites, preserving startup events.
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

  /** Named saves that exist but cannot be read, with why. */
  unreadableNamedSaves(): readonly { readonly saveId: string; readonly name: string; readonly reason: string }[] {
    return saveRepository.unreadable();
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
    const result = await this.loadSaveData(snapshot.data);
    return result.ok ? { ok: true, snapshot } : { ok: false, saveId, message: result.message };
  }

  /** Summary of the recovery autosave for the Load window, if there is one. */
  autosaveSummary(): { readonly mapId: string; readonly playTimeMs: number } | undefined {
    const data = saveRepository.readRecovery();
    return data ? { mapId: data.location.mapId, playTimeMs: data.playTimeMs } : undefined;
  }

  /** Travels into the recovery autosave (Continue, or its row in the Load window). */
  loadAutosave(): { readonly ok: true } | { readonly ok: false; readonly message: string } {
    const recovery = saveRepository.readRecovery();
    if (!recovery) return { ok: false, message: 'There is no autosave yet.' };
    saveRepository.markLegacyMigrationComplete();
    return this.queueNavigation(recovery, 'load', recovery.location.mapId)
      ? { ok: true }
      : { ok: false, message: 'The autosave could not be opened.' };
  }

  /** Checks a save against its map, then travels into it (the page reloads into the saved world). */
  private async loadSaveData(data: GameSaveData): Promise<{ readonly ok: true } | { readonly ok: false; readonly message: string }> {
    const { mapId } = data.location;
    let loadedMap: Awaited<ReturnType<typeof mapRepository.load>>;
    try {
      loadedMap = await mapRepository.load(mapId);
    } catch (error) {
      return { ok: false, message: `The saved map '${mapId}' could not be read: ${error instanceof Error ? error.message : String(error)}` };
    }
    if (!loadedMap) return { ok: false, message: `The authored map '${mapId}' is unavailable.` };
    if (!this.isLocationInsideMap(data.location, loadedMap.dimensions.width, loadedMap.dimensions.height)) {
      return { ok: false, message: 'The saved player location is invalid.' };
    }
    return this.queueNavigation(data, 'load', loadedMap.map.mapId)
      ? { ok: true }
      : { ok: false, message: 'The load request could not be started.' };
  }

  /** Play time of the installed run so far. */
  playTimeMs(): number {
    return this.playTimeBaseMs + Math.max(0, Date.now() - this.playTimeStartedAt);
  }

  /** True when there is a run to continue: the autosave or any named save. */
  canContinue(): boolean {
    return this.hasSave() || this.listNamedSaves().length > 0;
  }

  /**
   * Travels into the newest run: the recovery autosave (written throughout
   * play), or else the most recently updated named save.
   */
  async continueLatest(): Promise<LoadResult | { readonly ok: true }> {
    if (saveRepository.readRecovery()) return this.loadAutosave();
    const newest = [...this.listNamedSaves()].sort((left, right) => right.updatedAt - left.updatedAt)[0];
    if (!newest) return { ok: false, message: 'There is no saved game yet.' };
    return this.loadNamedSave(newest.saveId);
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
    // A defeated slime is never autosaved: loading the autosave (from the
    // defeat screen too) returns to the last moment it was alive.
    if (gameState.hp <= 0) return false;
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

import { worldProgress } from '../features/progression/WorldProgress';
import { saveRepository } from '../infrastructure/persistence/SaveRepository';
import { STORAGE_KEYS } from '../infrastructure/persistence/storageKeys';
import { playerInventory } from '../systems/Inventory';
import { questTracker } from '../quests/QuestTracker';
import { gameEvents } from './EventBus';
import { gameState } from './GameState';

class SaveSystem {
  private autoSaveStarted = false;
  private autoSaveTimer: number | undefined;

  startAutoSave(): void {
    if (this.autoSaveStarted) return;
    this.autoSaveStarted = true;
    gameEvents.on('coins.changed', this.scheduleSave, this);
    gameEvents.on('boost.changed', this.scheduleSave, this);
    gameEvents.on('hp.changed', this.scheduleSave, this);
    gameEvents.on('xp.changed', this.scheduleSave, this);
    gameEvents.on('energy.changed', this.scheduleSave, this);
    gameEvents.on('perk.taken', this.scheduleSave, this);
    gameEvents.on('inventory.changed', this.scheduleSave, this);
    gameEvents.on('weapon.loadout.changed', this.scheduleSave, this);
    gameEvents.on('weapon.equipped', this.scheduleSave, this);
    gameEvents.on('quest.changed', this.scheduleSave, this);
    gameEvents.on('world.progress.changed', this.scheduleSave, this);
  }

  save(slot = STORAGE_KEYS.save): boolean {
    const saved = saveRepository.write({
      player: gameState.serialize(),
      inventory: playerInventory.serialize(),
      quests: questTracker.serialize(),
      world: worldProgress.serialize(),
    }, slot);

    if (saved) gameEvents.emit('save.done', { slot });
    return saved;
  }

  load(slot = STORAGE_KEYS.save): boolean {
    const saved = saveRepository.read(slot);
    if (!saved) return false;

    gameState.load(saved.data.player);
    playerInventory.load(saved.data.inventory);
    questTracker.load(saved.data.quests);
    worldProgress.load(saved.data.world);
    gameEvents.emit('save.loaded', { slot });
    return true;
  }

  hasSave(slot = STORAGE_KEYS.save): boolean {
    return saveRepository.read(slot) !== null;
  }

  deleteSave(slot = STORAGE_KEYS.save): void {
    saveRepository.remove(slot);
  }

  savedAt(slot = STORAGE_KEYS.save): number | null {
    return saveRepository.read(slot)?.savedAt ?? null;
  }

  private scheduleSave = (): void => {
    if (this.autoSaveTimer !== undefined) window.clearTimeout(this.autoSaveTimer);
    this.autoSaveTimer = window.setTimeout(() => {
      this.autoSaveTimer = undefined;
      this.save();
    }, 250);
  };
}

export const saveSystem = new SaveSystem();
export { SAVE_SCHEMA_VERSION } from '../infrastructure/persistence/SaveSchema';
export { STORAGE_KEYS } from '../infrastructure/persistence/storageKeys';

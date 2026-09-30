import type { GameStateData } from '../../core/GameState';
import { createInitialQuestStates } from '../quests/QuestCatalog';
import type { GameLocationData, GameSaveData } from '../../infrastructure/persistence/SaveSchema';
import { PLAYER_CONFIG } from '../player';
import { GAME_CONSTANTS } from '../../Constant';
import level1Map from '../maps/level-1.map.json' with { type: 'json' };

const INITIAL_MAP_ID = level1Map.mapId;
const INITIAL_AREA_ID = INITIAL_MAP_ID;
const INITIAL_SPAWN = level1Map.player.spawn;

const INITIAL_PLAYER: GameStateData = {
  schemaVersion: 5,
  coins: 50,
  boostBonus: 0,
  hp: PLAYER_CONFIG.stats.maxHp,
  energy: PLAYER_CONFIG.stats.maxEnergy,
  gooHearts: 0,
  attributes: { ...PLAYER_CONFIG.attributes },
  equipment: {
    weaponId: null,
    weaponSlots: [null, null, null, null, null, null],
  },
};

export function initialLocation(): GameLocationData {
  return {
    areaId: INITIAL_AREA_ID,
    mapId: INITIAL_MAP_ID,
    x: INITIAL_SPAWN.x,
    y: INITIAL_SPAWN.y,
    facing: 'down',
  };
}

export function createInitialRunState(): GameSaveData {
  return {
    player: {
      ...INITIAL_PLAYER,
      attributes: { ...INITIAL_PLAYER.attributes },
      equipment: {
        ...INITIAL_PLAYER.equipment,
        weaponSlots: [...INITIAL_PLAYER.equipment.weaponSlots],
      },
    },
    inventory: {
      maxSlots: GAME_CONSTANTS.inventory.initialMaxSlots,
      slots: [],
    },
    quests: createInitialQuestStates().map((quest) => ({
      ...quest,
      progress: { ...quest.progress },
      consumedFactIds: Object.fromEntries(Object.entries(quest.consumedFactIds ?? {}).map(([id, facts]) => [id, [...facts]])),
    })),
    location: initialLocation(),
    world: {
      discoveredAreas: [INITIAL_AREA_ID],
      defeatedBossIds: [],
      completedDungeonIds: [],
      maps: {},
    },
    playTimeMs: 0,
  };
}

export const INITIAL_RUN = {
  areaId: INITIAL_AREA_ID,
  mapId: INITIAL_MAP_ID,
  spawn: INITIAL_SPAWN,
  create: createInitialRunState,
} as const;

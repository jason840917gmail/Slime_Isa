import type { GameStateData } from '../../core/GameState';
import type { InventorySlot } from '../../core/types';
import { QUEST_DEFS, type QuestState } from '../../quests/Quest';
import type { GameLocationData, GameSaveData } from '../../infrastructure/persistence/SaveSchema';
import { PLAYER_CONFIG } from '../player';
import level1Map from '../maps/level-1.map.json' with { type: 'json' };

const INITIAL_MAP_ID = level1Map.mapId;
const INITIAL_AREA_ID = INITIAL_MAP_ID;
const INITIAL_SPAWN = level1Map.player.spawn;

const INITIAL_PLAYER: GameStateData = {
  schemaVersion: 2,
  coins: 50,
  boostBonus: 0,
  totalFriends: 0,
  level: 1,
  xp: 0,
  hp: PLAYER_CONFIG.progression.baseMaxHp,
  maxHpBonus: 0,
  energy: PLAYER_CONFIG.progression.baseMaxEnergy,
  maxEnergyBonus: 0,
  skillPoints: 0,
  perks: {},
  attributes: { ...PLAYER_CONFIG.attributes },
  equipment: {
    weaponId: null,
    weaponSlots: [null, null, null, null, null, null],
  },
};

const INITIAL_INVENTORY: readonly InventorySlot[] = [];

function initialQuests(): QuestState[] {
  return QUEST_DEFS.map((definition) => ({
    id: definition.id,
    status: 'active',
    progress: Object.fromEntries(definition.objectives.map((objective) => [objective.id, 0])),
  }));
}

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
      perks: {},
      attributes: { ...INITIAL_PLAYER.attributes },
      equipment: {
        ...INITIAL_PLAYER.equipment,
        weaponSlots: [...INITIAL_PLAYER.equipment.weaponSlots],
      },
    },
    inventory: INITIAL_INVENTORY.map((slot) => ({ ...slot })),
    quests: initialQuests().map((quest) => ({ ...quest, progress: { ...quest.progress } })),
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

import type { QuestDefinition } from '../types';

export const gatherBuildingMaterials: QuestDefinition = {
  id: 'gather-building-materials',
  definitionVersion: 1,

  title: 'Gather Building Materials',
  description: 'Gather basic materials to prepare for the journey ahead.',
  category: 'mandatory',

  prerequisites: [
    { kind: 'area-entered', areaIds: ['level-1'] },
  ],
  acquisition: { kind: 'automatic' },

  stages: [
    {
      id: 'gather-materials',
      title: 'Gather Materials',
      description: 'Collect wood and stone around the starting area.',
      objectives: [
        {
          id: 'collect-wood',
          kind: 'collect',
          label: 'Collect wood',
          target: 30,
          itemIds: ['wood'],
        },
        {
          id: 'collect-stone',
          kind: 'collect',
          label: 'Collect stone',
          target: 30,
          itemIds: ['stone'],
        },
      ],
    },
  ],

  completion: { kind: 'automatic' },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'forbidden' },
  rewards: {},
};

import type { WorldDropPoint } from './WorldDropMotion';

export interface WorldDropDefinition {
  readonly objectId: string;
  readonly visualId: string;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

export type WorldDropRequest =
  | {
      readonly mode: 'launch';
      readonly source: WorldDropPoint;
      readonly destination: WorldDropPoint;
      readonly launchIndex: number;
      readonly drop: WorldDropDefinition;
    }
  | {
      readonly mode: 'settled';
      readonly destination: WorldDropPoint;
      readonly drop: WorldDropDefinition;
    };

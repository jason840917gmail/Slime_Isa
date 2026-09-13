import type { RuntimeNodeId, SceneId } from '../../content/scenes/identifiers';

export type SceneLifecyclePhase =
  | 'enter'
  | 'ready'
  | 'process'
  | 'physics-process'
  | 'input'
  | 'unhandled-input'
  | 'signal'
  | 'mutation'
  | 'exit'
  | 'dispose';

export interface SceneDiagnostic {
  readonly sceneId?: SceneId;
  readonly nodePath: string;
  readonly runtimeId: RuntimeNodeId;
  readonly phase: SceneLifecyclePhase;
  readonly message: string;
  readonly error: unknown;
}

export type SceneDiagnosticSink = (diagnostic: SceneDiagnostic) => void;

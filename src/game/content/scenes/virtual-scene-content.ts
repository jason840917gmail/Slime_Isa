import type { SceneResourceDocument } from './resources/types';
import type { SceneDocument } from './types';

/** Vite replaces this module with recursively discovered authored scenes/resources. */
export const sceneDocuments: readonly SceneDocument[] = [];
export const sceneResourceDocuments: readonly SceneResourceDocument[] = [];

import type Phaser from 'phaser';
import type { SourceFrameDimensions, SourceOcclusionBounds } from '../../presentation/WorldOcclusion';

/** Transitional Phaser object registration for world drops and legacy consumers. */
export interface PhaserObjectRegistration {
  readonly image: Phaser.GameObjects.Image;
  readonly objectId: string;
  readonly instanceId: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
  readonly npcDefinitionId?: string;
}

export interface ObjectOccluderRegistration {
  readonly id: string;
  readonly owner: Phaser.GameObjects.Image | Phaser.GameObjects.Sprite;
  readonly sourceFrame: SourceFrameDimensions;
  readonly bounds: SourceOcclusionBounds;
  readonly getDepth: () => number;
}

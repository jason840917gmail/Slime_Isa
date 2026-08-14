import type { LayeredAnimationDocument, NormalizedLayeredAnimationDocument } from '../../shared/animation';

export type EffectDirection = 'right' | 'left' | 'up' | 'down';

export interface EffectDefinition {
  readonly version: 1;
  readonly effectId: string;
  readonly displayName: string;
  readonly default?: LayeredAnimationDocument;
  readonly directions?: Partial<Readonly<Record<EffectDirection, LayeredAnimationDocument>>>;
  readonly mirrorLeftFromRight?: boolean;
  readonly mirrorUpFromDown?: boolean;
}

export interface NormalizedEffectVariant {
  readonly animation: NormalizedLayeredAnimationDocument;
  readonly authored: boolean;
  readonly source: EffectDirection | 'default';
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}

export interface NormalizedEffectDefinition {
  readonly version: 1;
  readonly effectId: string;
  readonly displayName: string;
  readonly variants: Readonly<Record<EffectDirection, NormalizedEffectVariant>>;
}

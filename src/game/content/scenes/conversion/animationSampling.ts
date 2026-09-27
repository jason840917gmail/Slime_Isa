/**
 * Pure animation/geometry helpers shared by the scene converters and their
 * parity tests. Everything here delegates to the exact shared functions the
 * pre-scene runtime used (layered animation composition, directional
 * inheritance, weapon normalization and Arcade body bounds), so generated
 * scene tracks cannot drift from the authored-content semantics.
 */
import {
  composeAnimationVisualTransform,
  layeredTimelineFrameCount,
  normalizeLayeredAnimation,
  resolveLayeredAnimationFrame,
  type ComposedAnimationVisualTransform,
  type LayeredAnimationDocument,
  type LayeredAnimationHostTransform,
  type NormalizedLayeredAnimationDocument,
} from '../../../shared/animation';
import { resolveEffectiveArcadeBodyBoundsRelativeToAnchor, type CollisionShapeDocument } from '../../../shared/collisionShapes';

export {
  composeAnimationVisualTransform,
  layeredTimelineFrameCount,
  materializeDirectionalAnimation,
  normalizeLayeredAnimation,
  resolveLayeredAnimationFrame,
} from '../../../shared/animation';
export { normalizeWeaponDefinition } from '../../weapons/normalize';
export { resolveWeaponPresentationOffsetY } from '../../weapons/presentation';
export { EFFECT_DIRECTIONS, normalizeEffectDefinition, resolveEffectVariant } from '../../effects/normalize';
export { resolveEffectiveArcadeBodyBoundsRelativeToAnchor } from '../../../shared/collisionShapes';

export interface SampledLayer extends ComposedAnimationVisualTransform {
  readonly layerId: string;
  readonly assetId: string;
  readonly sourceFrame: number;
  readonly layerIndex: number;
  readonly relativeDepth: number;
}

export interface SampledLayeredFrame {
  readonly frame: number;
  readonly layers: readonly SampledLayer[];
}

/** Host placement of a layered animation relative to the node that owns its sprites. */
export interface LayeredSamplingHost {
  readonly offsetX?: number;
  readonly offsetY?: number;
  readonly mirrorX?: boolean;
  readonly mirrorY?: boolean;
}

/**
 * Samples every timeline frame of a layered animation through
 * `resolveLayeredAnimationFrame` + `composeAnimationVisualTransform`, the same
 * pair `LayeredAnimationVisual` used at runtime. `baseDepth` is zero, so the
 * returned `depth` is the layer's relative depth within its host.
 */
export function sampleLayeredAnimation(
  animation: LayeredAnimationDocument | NormalizedLayeredAnimationDocument,
  host: LayeredSamplingHost = {},
): readonly SampledLayeredFrame[] {
  const normalized = normalizeLayeredAnimation(animation as LayeredAnimationDocument);
  const hostTransform: LayeredAnimationHostTransform = {
    x: host.offsetX ?? 0,
    y: host.offsetY ?? 0,
    baseDepth: 0,
    rotationRad: 0,
    mirrorX: host.mirrorX === true,
    mirrorY: host.mirrorY === true,
  };
  const frameCount = layeredTimelineFrameCount(normalized);
  const frames: SampledLayeredFrame[] = [];
  for (let frame = 0; frame < frameCount; frame += 1) {
    frames.push({
      frame,
      layers: resolveLayeredAnimationFrame(normalized, frame).map((layer) => ({
        ...composeAnimationVisualTransform(layer, hostTransform),
        layerId: layer.layerId,
        assetId: layer.assetId,
        sourceFrame: layer.sourceFrame,
        layerIndex: layer.layerIndex,
        relativeDepth: layer.relativeDepth,
      })),
    });
  }
  return frames;
}

/**
 * Local ground point (feet) of a character body: the bottom-centre of the
 * Arcade body bounds, which is what the old runtime sorted by
 * (`resolveWorldDepth(resolveBodyBottom(body))`).
 */
export function bodyDepthAnchor(body: CollisionShapeDocument): readonly [number, number] {
  const bounds = resolveEffectiveArcadeBodyBoundsRelativeToAnchor(body);
  return [body.centerOffsetX ?? 0, bounds.maxY];
}

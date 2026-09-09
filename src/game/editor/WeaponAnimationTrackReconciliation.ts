import { layeredTimelineFrameCount, type LayeredAnimationDocument } from '../shared/animation';
import type { WeaponAttackTrackDocument } from '../content/weapons/types';

/** Reprojects attack timing when an authored animation's sampling grid changes. */
export function reconcileWeaponAttackTrack(
  track: WeaponAttackTrackDocument,
  previousAnimation: LayeredAnimationDocument,
  nextAnimation: LayeredAnimationDocument,
): WeaponAttackTrackDocument {
  const frameCount = layeredTimelineFrameCount(nextAnimation);
  const fpsChanged = previousAnimation.framesPerSecond !== nextAnimation.framesPerSecond;
  const projectFrom = (frame: number): number => fpsChanged
    ? Math.round(frame / previousAnimation.framesPerSecond * nextAnimation.framesPerSecond)
    : frame;
  const projectThrough = (frame: number): number => fpsChanged
    ? Math.round((frame + 1) / previousAnimation.framesPerSecond * nextAnimation.framesPerSecond) - 1
    : frame;
  const spans = track.hitboxSpans
    .flatMap((span) => {
      const from = projectFrom(span.from);
      const through = Math.min(projectThrough(span.through), frameCount - 1);
      return from >= 0 && from < frameCount && through >= from ? [{ ...span, from, through }] : [];
    })
    .sort((left, right) => left.from - right.from || left.through - right.through || left.hitboxId.localeCompare(right.hitboxId));
  const mergedSpans: Array<{ readonly hitboxId: string; readonly from: number; readonly through: number }> = [];
  for (const span of spans) {
    const previous = mergedSpans[mergedSpans.length - 1];
    if (previous && previous.hitboxId === span.hitboxId && previous.through + 1 >= span.from) mergedSpans[mergedSpans.length - 1] = { ...previous, through: Math.max(previous.through, span.through) };
    else mergedSpans.push(span);
  }
  const events = track.events?.flatMap((event) => {
    const at = projectFrom(event.at);
    return at >= 0 && at < frameCount ? [{ ...event, at }] : [];
  });
  return { ...track, hitboxSpans: mergedSpans, ...(track.events ? { events } : {}) };
}
